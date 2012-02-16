//
//  AVAssetReaderConvertMaxvid.h
//
//  Created by Moses DeJong on 2/4/12.
//
//  License terms defined in License.txt.
//
//  This module implements a H264 to MVID decoder that can be used to
//  save the raw bits of a H264 video into a file.

#import "AVAssetReaderConvertMaxvid.h"

#import "maxvid_file.h"

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

#ifdef EXTRA_CHECKS
#define ALWAYS_GENERATE_ADLER
#endif // EXTRA_CHECKS

#if defined(HAS_AVASSET_READER_CONVERT_MAXVID)

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVAssetReader.h>
#import <AVFoundation/AVAssetReaderOutput.h>

#import <CoreMedia/CMSampleBuffer.h>

#import "CGFrameBuffer.h"

// Private API

@interface AVAssetReaderConvertMaxvid ()

@property (nonatomic, retain) AVAssetReader *aVAssetReader;
@property (nonatomic, retain) AVAssetReaderOutput *aVAssetReaderOutput;

- (BOOL) renderIntoFramebuffer:(CMSampleBufferRef)sampleBuffer frameBuffer:(CGFrameBuffer**)frameBufferPtr;

@end


@implementation AVAssetReaderConvertMaxvid

@synthesize assetURL = m_assetURL;
@synthesize mvidPath = m_mvidPath;
@synthesize aVAssetReader = m_aVAssetReader;
@synthesize aVAssetReaderOutput = m_aVAssetReaderOutput;
@synthesize genAdler = m_genAdler;

- (void) dealloc
{  
  self.assetURL = nil;
  self.mvidPath = nil;
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
  
  NSArray *availableMetadataFormats = videoTrack.availableMetadataFormats;
  
  NSLog(@"availableMetadataFormats %@", availableMetadataFormats);
  
  // track must be self contained
  
  NSAssert(videoTrack.isSelfContained, @"isSelfContained");
  
  // playback framerate
  
  CMTimeRange timeRange = videoTrack.timeRange;
  
  float duration = (float)CMTimeGetSeconds(timeRange.duration);
  
  float nominalFrameRate = videoTrack.nominalFrameRate;
    
  self->frameDuration = 1.0 / nominalFrameRate;

  float numFramesFloat = duration / self->frameDuration;
  int numFrames = round( numFramesFloat );
  
  NSLog(@"frame rate = %0.2f FPS", nominalFrameRate);
  NSLog(@"duration = %0.2f S", duration);
  NSLog(@"numFrames = %0.4f -> %d", numFramesFloat, numFrames);
  
  self->totalNumFrames = numFrames;
  
  AVAssetReaderTrackOutput *aVAssetReaderOutput = [[[AVAssetReaderTrackOutput alloc]
                                                    initWithTrack:videoTrack outputSettings:videoSettings] autorelease];
  
  NSAssert(aVAssetReaderOutput, @"AVAssetReaderVideoCompositionOutput failed");
  
  // Read video data from the inidicated tracks of video data
  
  [self.aVAssetReader addOutput:aVAssetReaderOutput];
  
  self.aVAssetReaderOutput = aVAssetReaderOutput;
  
  return TRUE;
}

// Read video data from a single track (only one video track is supported anyway)

- (BOOL) decodeAssetURL
{
  BOOL worked;
  BOOL retstatus = FALSE;
  
#ifdef ALWAYS_GENERATE_ADLER
  self.genAdler = TRUE;
#endif // ALWAYS_GENERATE_ADLER
  
  MVFileHeader *mvHeader = NULL;
  MVFrame *mvFramesArray = NULL;
  FILE *maxvidOutFile = NULL;
  AVAssetReader *aVAssetReader = nil;
  
  worked = [self setupAsset];
  if (worked == FALSE) {
    goto retcode;
  }
    
  CMSampleBufferRef sampleBuffer = NULL;
  
  int frame = 0;
  int numWritten = 0;
  
  maxvidOutFile = fopen([self.mvidPath UTF8String], "wb");
  if (maxvidOutFile == NULL) {
    goto retcode;
  }

  mvHeader = malloc(sizeof(MVFileHeader));
  if (mvHeader == NULL) {
    goto retcode;
  }
  memset(mvHeader, 0, sizeof(MVFileHeader));
  
  // Write zeroed file header
  
  numWritten = fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    goto retcode;
  }
  
  // We need to have figured out how many frames there are in the video before
  // decoding frames begins.
  
  int numOutputFrames = self->totalNumFrames;
  
  // Write zeroed frames header
  
  const uint32_t framesArrayNumBytes = sizeof(MVFrame) * numOutputFrames;
  mvFramesArray = malloc(framesArrayNumBytes);
  if (mvFramesArray == NULL) {
    goto retcode;
  }
  memset(mvFramesArray, 0, framesArrayNumBytes);
  
  numWritten = fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
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
  
  long offset = ftell(maxvidOutFile);
  
  BOOL writeFailed = FALSE;
  
  // This framebuffer object will be the destination of a render operation
  // for a given frame. Multiple frames must always be the same size,
  // so a common render buffer will be allocated.
  
  CGFrameBuffer *frameBuffer = nil;
  
  while ((writeFailed == FALSE) && ([aVAssetReader status] == AVAssetReaderStatusReading))
  {
    NSAutoreleasePool *inner_pool = [[NSAutoreleasePool alloc] init];
    
    NSLog(@"READING frame %d", frame);
    
    sampleBuffer = [self.aVAssetReaderOutput copyNextSampleBuffer];
    
    if (sampleBuffer) {
      NSLog(@"WRITTING frame %d", frame);
      
      MVFrame *mvFrame = &mvFramesArray[frame];
      
      BOOL worked = [self renderIntoFramebuffer:sampleBuffer frameBuffer:&frameBuffer];
      NSAssert(worked, @"worked");
      
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
      } else {
        NSAssert(movieWidth == width, @"movieWidth");
        NSAssert(movieHeight == height, @"movieHeight");
      }
      
      // Calculate how many bytes make up the image via (bytesPerRow * height). The
      // numBytes value may be padded out to fit to an OS page bound.
      
      int bufferSize = movieWidth * movieHeight * frameBuffer.bytesPerPixel;
      int expectedBufferSize = (movieWidth * movieHeight * sizeof(uint32_t));
      NSAssert(bufferSize == expectedBufferSize, @"framebuffer size");
      
      // Skip to next page bound
      
      offset = maxvid_file_padding_before_keyframe(maxvidOutFile, offset);
      
      maxvid_frame_setoffset(mvFrame, (uint32_t)offset);
      
      maxvid_frame_setkeyframe(mvFrame);
      
      // write entire buffer of raw 32bit pixels to the file.
      // bitmap info is native (kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little)
      
      numWritten = fwrite(frameBuffer.pixels, bufferSize, 1, maxvidOutFile);
      if (numWritten != 1) {
        writeFailed = TRUE;
      } else {
        // Finish emitting frame data
        
        uint32_t offsetBefore = (uint32_t)offset;
        offset = ftell(maxvidOutFile);
        uint32_t length = ((uint32_t)offset) - offsetBefore;
        
        NSAssert((length % 2) == 0, @"offset length must be even");
        assert((length % 4) == 0); // must be in terms of whole words
        
        maxvid_frame_setlength(mvFrame, length);
        
        // Generate adler32 for pixel data and save into frame data
        
        if (self.genAdler) {
          mvFrame->adler = maxvid_adler32(0, (unsigned char*)frameBuffer.pixels, bufferSize);
          assert(mvFrame->adler != 0);
        }
        
        // zero pad to next page bound
        
        offset = maxvid_file_padding_after_keyframe(maxvidOutFile, offset);
        assert(offset > 0); // silence compiler/analyzer warning        
      }
      
      CFRelease(sampleBuffer);
    } else if ([aVAssetReader status] == AVAssetReaderStatusReading) {
      AVAssetReaderStatus status = aVAssetReader.status;
      NSError *error = aVAssetReader.error;
      
      NSLog(@"status = %d", status);
      NSLog(@"error = %@", [error description]);
    }
    
    frame++;
    
    [inner_pool drain];
  }

  // Explicitly release the retained frameBuffer
  
  [frameBuffer release];

  mvHeader->magic = 0; // magic still not valid
  mvHeader->width = movieWidth;
  mvHeader->height = movieHeight;
  mvHeader->bpp = 24; // no alpha for H.264 video

  mvHeader->frameDuration = self->frameDuration;
  assert(mvHeader->frameDuration > 0.0);
  
  mvHeader->numFrames = numOutputFrames;
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  numWritten = fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    goto retcode;
  }
  
  numWritten = fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    goto retcode;
  }  
  
  // Once all valid data and headers have been written, it is now safe to write the
  // file header magic number. This ensures that any threads reading the first word
  // of the file looking for a valid magic number will only ever get consistent
  // data in a read when a valid magic number is read.
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  uint32_t magic = MV_FILE_MAGIC;
  numWritten = fwrite(&magic, sizeof(uint32_t), 1, maxvidOutFile);
  if (numWritten != 1) {
    goto retcode;
  }
  
  retstatus = TRUE;
  
retcode:
  
  [aVAssetReader cancelReading];
  
  if (mvHeader) {
    free(mvHeader);
  }
  
  if (mvFramesArray) {
    free(mvFramesArray);
  }
  
  if (maxvidOutFile) {
    fclose(maxvidOutFile);
  }
  
  if (retstatus) {
    NSLog(@"wrote %@", self.mvidPath);
  } else {
    NSLog(@"failed to write %@", self.mvidPath);    
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
  
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  
  void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
  
  size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
  
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
  }
  
  [frameBuffer renderCGImage:cgImageRef];
                                
  CGImageRelease(cgImageRef);
                                
  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
  
  return TRUE;
}

@end

#endif // HAS_AVASSET_READER_CONVERT_MAXVID
