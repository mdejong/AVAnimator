//
//  AVAssetReaderConvertMaxvid.m
//
//  Created by Moses DeJong on 2/4/12.
//
//  License terms defined in License.txt.

#import "AVAssetReaderConvertMaxvid.h"

#import "maxvid_file.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#import "AVFrame.h"

#import "AVAssetFrameDecoder.h"

#import "CGFrameBuffer.h"

#include "AVStreamEncodeDecode.h"

#if __has_feature(objc_arc)
#else
#import "AutoPropertyRelease.h"
#endif // objc_arc

//#define LOGGING

NSString * const AVAssetReaderConvertMaxvidCompletedNotification = @"AVAssetReaderConvertMaxvidCompletedNotification";

// Private API

@interface AVAssetReaderConvertMaxvid ()

@property (nonatomic, retain) AVAssetFrameDecoder *frameDecoder;

@property (nonatomic, retain) CGFrameBuffer *resizeFramebuffer;

@end

@implementation AVAssetReaderConvertMaxvid

@synthesize assetURL = m_assetURL;
@synthesize frameDecoder = m_frameDecoder;
@synthesize wasSuccessful = m_wasSuccessful;

#if defined(HAS_LIB_COMPRESSION_API)
@synthesize compressed = m_compressed;
#endif // HAS_LIB_COMPRESSION_API

- (void) dealloc
{
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVAssetReaderConvertMaxvid.class];
  [super dealloc];
#endif // objc_arc
}

+ (AVAssetReaderConvertMaxvid*) aVAssetReaderConvertMaxvid
{
  AVAssetReaderConvertMaxvid *obj = [[AVAssetReaderConvertMaxvid alloc] init];
  obj.genV3 = TRUE; // enable extended file size out to 64bit offsets
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

// This utility method will setup the asset so that it is opened and ready
// to decode frames of video data.

- (BOOL) setupAssetDecoder
{
  NSAssert(self.assetURL, @"assetURL");
  NSAssert(self.mvidPath, @"mvidPath");
  
  AVAssetFrameDecoder *frameDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  
  self.frameDecoder = frameDecoder;
  
  NSString *path = [self.assetURL path];
  
  BOOL worked = [frameDecoder openForReading:path];
  if (worked == FALSE) {
    return FALSE;
  }
  
  worked = [frameDecoder allocateDecodeResources];
  if (worked == FALSE) {
    return FALSE;
  }
  
  return TRUE;
}

// Emit frame of data

- (BOOL) blockingDecodeEmitFrame:(AVFrame*)avFrame
{
  BOOL worked;

  CGFrameBuffer *frameBuffer = avFrame.cgFrameBuffer;
  NSAssert(frameBuffer, @"frameBuffer");
  
  NSAssert(frameBuffer.isLockedByDataProvider, @"isLockedByDataProvider");
  
  int bufferSize;
  void *pixelsPtr;
  
  // If the frame width and height do not match the expected
  // output width and height then the frame data must be resized
  // before it can be written as pixels.
  
  int width = (int) self.movieSize.width;
  int height = (int) self.movieSize.height;
  
  BOOL sameWidth = (width == frameBuffer.width);
  BOOL sameHeight = (height == frameBuffer.height);
  
  if (!sameWidth || !sameHeight) {
    CGFrameBuffer *resizeFramebuffer = self.resizeFramebuffer;
    
    if (resizeFramebuffer == nil) {
      resizeFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:frameBuffer.bitsPerPixel width:self.movieSize.width height:self.movieSize.height];
      
      NSAssert(resizeFramebuffer, @"resizeFramebuffer with dimensions %d x %d", (int)self.movieSize.width, (int)self.movieSize.height);
      
      self.resizeFramebuffer = resizeFramebuffer;
    }
    
    CGImageRef cgImage = avFrame.image.CGImage;
      
    [resizeFramebuffer renderCGImage:cgImage];
    
    // Calculate how many bytes make up the image via (bytesPerRow * height). The
    // numBytes value may be padded out to fit to an OS page bound. If the buffer
    // is padded in the case of an odd number of pixels, pass the buffer size
    // including the padding pixels.
    
    bufferSize  = (int) resizeFramebuffer.numBytes;
    pixelsPtr = resizeFramebuffer.pixels;
  } else {
    
    // Calculate how many bytes make up the image via (bytesPerRow * height). The
    // numBytes value may be padded out to fit to an OS page bound. If the buffer
    // is padded in the case of an odd number of pixels, pass the buffer size
    // including the padding pixels.
    
    bufferSize  = (int) frameBuffer.numBytes;
    pixelsPtr = frameBuffer.pixels;
  }
  
#if defined(HAS_LIB_COMPRESSION_API)
  // If compression is used, then generate a compressed buffer and write it as
  // a keyframe.
  
  if (self.compressed) {
    NSData *pixelData = [NSData dataWithBytesNoCopy:pixelsPtr length:bufferSize freeWhenDone:NO];
    
    // FIXME: make this mutable data a member so that it is not allocated
    // in every loop.
    
    NSMutableData *mEncodedData = [NSMutableData data];
    
    [AVStreamEncodeDecode streamDeltaAndCompress:pixelData
                                     encodedData:mEncodedData
                                             bpp:self.bpp
                                       algorithm:COMPRESSION_LZ4];
    
    //int src_size = bufferSize;
    assert(mEncodedData.length < 0xFFFFFFFF);
    int dst_size = (int) mEncodedData.length;
    
    //printf("compressed frame size %d kB down to %d kB\n", (int)src_size/1000, (int)dst_size/1000);
    
    // Calculate adler based on original pixels (not the compressed representation)
    
    uint32_t adler = 0;
    
    if (self.genAdler) {
      adler = maxvid_adler32(0, (unsigned char*)pixelsPtr, bufferSize);
    }
    
    worked = [self writeKeyframe:(char*)mEncodedData.bytes bufferSize:(int)dst_size adler:adler isCompressed:TRUE];
  } else
#endif // HAS_LIB_COMPRESSION_API
  {
    // write entire buffer of raw 32bit pixels to the file.
    // bitmap info is native (kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little)
    
    worked = [self writeKeyframe:pixelsPtr bufferSize:bufferSize];
  }
  
  if (worked) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// Read video data from a single track (only one video track is supported anyway)

- (BOOL) blockingDecode
{
  BOOL worked;
  BOOL retstatus = FALSE;
  
  AVAssetFrameDecoder *frameDecoder = nil;
  
  self.wasSuccessful = FALSE;
  
  NSAssert(self.frameDecoder == nil, @"frameDecoder property should be nil");

  worked = [self setupAssetDecoder];
  if (worked == FALSE) {
    goto retcode;
  }
  
  frameDecoder = self.frameDecoder;
  
  self.totalNumFrames = (int) frameDecoder.numFrames;
  self.frameDuration = frameDecoder.frameDuration;
  
  if (CGSizeEqualToSize(CGSizeZero, self.movieSize)) {
    self.movieSize = CGSizeMake(frameDecoder.width, frameDecoder.height);
  }

  self.bpp = 24;
      
  worked = [self open];
  
  if (worked == FALSE) {
    goto retcode;
  }
  
  BOOL writeFailed = FALSE;

  int frameIndex;
  int numFrames = (int) frameDecoder.numFrames;
  
  for (frameIndex = 0; (frameIndex < numFrames) && (writeFailed == FALSE); frameIndex++) @autoreleasepool {
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    
    if (frame.isDuplicate) {
      [self writeNopFrame];
    } else {
      worked = [self blockingDecodeEmitFrame:frame];
      
      if (worked == FALSE) {
        writeFailed = TRUE;
      }
    }
  }

  if (writeFailed == FALSE) {
    // Double check that we did not write too few frames.
    
    NSAssert(frameIndex == self.totalNumFrames, @"frameIndex == totalNumFrames");
    NSAssert(self.frameNum == self.totalNumFrames, @"frameNum emitted");
    
    worked = [self rewriteHeader];    
  }
  
  [self close];
  
  if (worked == FALSE) {
    goto retcode;
  }
  
  retstatus = TRUE;
  
retcode:
  // Release resize framebuffer in case it is very large
  
  self.resizeFramebuffer = nil;
  
  // Explicitly release the frame decoder in case this frees up memory sooner.
  // An asset frame decoder can only be used once anyway
  
  [self.frameDecoder close];
  self.frameDecoder = nil;
  frameDecoder = nil;

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
  @autoreleasepool {
  
  [self blockingDecode];
  
  if (FALSE) {
    [self notifyDecodingDoneInMainThread];
  }
  
  [self performSelectorOnMainThread:@selector(notifyDecodingDoneInMainThread) withObject:nil waitUntilDone:TRUE];
  
  }
  
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
