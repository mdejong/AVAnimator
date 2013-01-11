//
//  AVAssetReaderConvertMaxvid.m
//
//  Created by Moses DeJong on 2/4/12.
//
//  License terms defined in License.txt.

#import "AVAssetReaderConvertMaxvid.h"

#import "maxvid_file.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#import "AVAssetFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "AutoPropertyRelease.h"

//#define LOGGING

NSString * const AVAssetReaderConvertMaxvidCompletedNotification = @"AVAssetReaderConvertMaxvidCompletedNotification";

// Private API

@interface AVAssetReaderConvertMaxvid ()

@property (nonatomic, retain) AVAssetFrameDecoder *frameDecoder;

@end

@implementation AVAssetReaderConvertMaxvid

@synthesize assetURL = m_assetURL;
@synthesize frameDecoder = m_frameDecoder;
@synthesize wasSuccessful = m_wasSuccessful;

- (void) dealloc
{
  [AutoPropertyRelease releaseProperties:self thisClass:AVAssetReaderConvertMaxvid.class];
  [super dealloc];
}

+ (AVAssetReaderConvertMaxvid*) aVAssetReaderConvertMaxvid
{
  AVAssetReaderConvertMaxvid *obj = [[AVAssetReaderConvertMaxvid alloc] init];
  return [obj autorelease];
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

- (BOOL) blockingDecodeEmitFrame:(CGFrameBuffer*)frameBuffer
{
  BOOL worked;

  NSAssert(frameBuffer, @"frameBuffer");
  
  // Calculate how many bytes make up the image via (bytesPerRow * height). The
  // numBytes value may be padded out to fit to an OS page bound. If the buffer
  // is padded in the case of an odd number of pixels, pass the buffer size
  // including the padding pixels.
  
  int bufferSize = frameBuffer.numBytes;
  void *pixelsPtr = frameBuffer.pixels;
  
  // write entire buffer of raw 32bit pixels to the file.
  // bitmap info is native (kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little)
  
  worked = [self writeKeyframe:pixelsPtr bufferSize:bufferSize];
  
  return worked;
}

// Read video data from a single track (only one video track is supported anyway)

- (BOOL) blockingDecode
{
  BOOL worked;
  BOOL retstatus = FALSE;
  
  self.wasSuccessful = FALSE;
  
  NSAssert(self.frameDecoder == nil, @"frameDecoder property should be nil");

  worked = [self setupAssetDecoder];
  if (worked == FALSE) {
    goto retcode;
  }
  
  AVAssetFrameDecoder *frameDecoder = self.frameDecoder;
  
  self.totalNumFrames = frameDecoder.numFrames;
  self.frameDuration = frameDecoder.frameDuration;
  self.movieSize = CGSizeMake(frameDecoder.width, frameDecoder.height);
  self.bpp = 24;
      
  worked = [self open];
  
  if (worked == FALSE) {
    goto retcode;
  }
  
  BOOL writeFailed = FALSE;

  int frameIndex;
  int numFrames = frameDecoder.numFrames;
  
  for (frameIndex = 0; (frameIndex < numFrames) && (writeFailed == FALSE); frameIndex++) {
    NSAutoreleasePool *inner_pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    
    if (frame.isDuplicate) {
      [self writeNopFrame];
    } else {
      worked = [self blockingDecodeEmitFrame:frame.cgFrameBuffer];
      
      if (worked == FALSE) {
        writeFailed = TRUE;
      }
    }
    
    [inner_pool drain];
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
  
  // Explicitly release the frame decoder in case this frees up memory sooner.
  // An asset frame decoder can only be used once anyway
  
  [self.frameDecoder close];
  self.frameDecoder = nil;

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
