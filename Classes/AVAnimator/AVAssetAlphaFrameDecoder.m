//
//  AVAssetAlphaFrameDecoder.m
//
//  Created by Moses DeJong on 1/4/13.
//
//  License terms defined in License.txt.

#import "AVAssetAlphaFrameDecoder.h"

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

#import "AVAssetJoinAlphaResourceLoader.h" // for rgb+alpha mix logic

#if defined(HAS_AVASSET_CONVERT_MAXVID)

//#define LOGGING

// External Privete API

@interface AVAssetJoinAlphaResourceLoader ()

+ (void) combineRGBAndAlphaPixels:(uint32_t)numPixels
                   combinedPixels:(uint32_t*)combinedPixels
                        rgbPixels:(uint32_t*)rgbPixels
                      alphaPixels:(uint32_t*)alphaPixels;

@end

// Private API

@interface AVAssetAlphaFrameDecoder ()

@property (nonatomic, retain) AVFrame *currentFrame;

@end

@implementation AVAssetAlphaFrameDecoder

@synthesize rgbAssetDecoder = m_rgbAssetDecoder;
@synthesize alphaAssetDecoder = m_alphaAssetDecoder;

@synthesize movieRGBFilename = m_movieRGBFilename;
@synthesize movieAlphaFilename = m_movieAlphaFilename;

@synthesize currentFrame = m_currentFrame;

- (void) dealloc
{
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVAssetAlphaFrameDecoder.class];
  [super dealloc];
#endif // objc_arc
}

+ (AVAssetAlphaFrameDecoder*) aVAssetAlphaFrameDecoder
{
  AVAssetAlphaFrameDecoder *obj = [[AVAssetAlphaFrameDecoder alloc] init];
  
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

// Note that openForReading:(NSString*)assetPath is not implemented for this
// class, instead invoke openForReading with no arguments after setting
// the movieRGBFilename and movieAlphaFilename properties.

- (BOOL) openForReading:(NSString*)assetPath
{
  [self doesNotRecognizeSelector:_cmd];
  return FALSE;
}

// Return TRUE if opening the rgb and alpha asset file is successful.
// This method could return FALSE when the file does not exist or
// it is the wrong format.

- (BOOL) openForReading
{
  BOOL worked;

  NSString *movieRGBFilename = self.movieRGBFilename;
  NSString *movieAlphaFilename = self.movieAlphaFilename;
  
  NSAssert(movieRGBFilename, @"movieRGBFilename");
  NSAssert(movieAlphaFilename, @"movieAlphaFilename");

  AVAssetFrameDecoder *rgbAssetDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  AVAssetFrameDecoder *alphaAssetDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];

  self.rgbAssetDecoder = rgbAssetDecoder;
  self.alphaAssetDecoder = alphaAssetDecoder;
  
  NSAssert(self.rgbAssetDecoder, @"rgbAssetDecoder");
  NSAssert(self.alphaAssetDecoder, @"alphaAssetDecoder");
  
  worked = [rgbAssetDecoder openForReading:movieRGBFilename];
  
  if (worked == FALSE) {
    NSLog(@"error: cannot open RGB mvid filename \"%@\"", movieRGBFilename);
    return FALSE;
  }

  worked = [alphaAssetDecoder openForReading:movieAlphaFilename];
  
  if (worked == FALSE) {
    NSLog(@"error: cannot open ALPHA mvid filename \"%@\"", movieAlphaFilename);
    return FALSE;
  }
  
  return TRUE;
}

// Rewind to begining of the rendered frames

- (void) rewind
{
  [self.rgbAssetDecoder rewind];
  [self.alphaAssetDecoder rewind];
}

- (AVFrame*) advanceToFrame:(NSUInteger)newFrameIndex
{
#ifdef LOGGING
  NSLog(@"advanceToFrame : from %d to %d", (int)frameIndex, (int)newFrameIndex);
#endif // LOGGING

  AVFrame *rgbFrame = [self.rgbAssetDecoder advanceToFrame:newFrameIndex];
  AVFrame *alphaFrame = [self.alphaAssetDecoder advanceToFrame:newFrameIndex];

  // Clear out previously held buffer ref
  
  self.currentFrame.image = nil;
  self.currentFrame.cgFrameBuffer = nil;
  self.currentFrame = nil;
  
  // Note that we do not release the frameBuffer because it is held as
  // the self.currentFrameBuffer property
  
  // Get CGFrameBuffer out of each frame and combine RGB and Alpha pixels

  CGFrameBuffer *rgbFrameBuffer = rgbFrame.cgFrameBuffer;
  CGFrameBuffer *alphaFrameBuffer = alphaFrame.cgFrameBuffer;

  CGFrameBuffer *combinedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:rgbFrameBuffer.width height:rgbFrameBuffer.height];
  
  // Join RBB + Alpha pixels
  
  uint32_t numPixels = (int)rgbFrameBuffer.width * (int)rgbFrameBuffer.height;
  uint32_t *combinedPixels = (uint32_t*)combinedFrameBuffer.pixels;
  uint32_t *rgbPixels = (uint32_t*)rgbFrameBuffer.pixels;
  uint32_t *alphaPixels = (uint32_t*)alphaFrameBuffer.pixels;
  
  [AVAssetJoinAlphaResourceLoader combineRGBAndAlphaPixels:numPixels
                  combinedPixels:combinedPixels
                       rgbPixels:rgbPixels
                     alphaPixels:alphaPixels];
  
  AVFrame *retFrame = [AVFrame aVFrame];

  retFrame.cgFrameBuffer = combinedFrameBuffer;
  [retFrame makeImageFromFramebuffer];
  // Drop ref to fraembuffer so that image contains the last ref
  retFrame.cgFrameBuffer = nil;
  
  self.currentFrame = retFrame;
  
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
  return self.currentFrame;
}

// Properties

- (NSUInteger) width
{
  return self.rgbAssetDecoder.width;
}

- (NSUInteger) height
{
  return self.rgbAssetDecoder.height;
}

- (BOOL) isOpen
{
  return self.rgbAssetDecoder.isOpen;
}

// Total frame count

- (NSUInteger) numFrames
{
  return self.rgbAssetDecoder.numFrames;
}

- (NSInteger) frameIndex
{
  return self.rgbAssetDecoder.frameIndex;
}

// Gettter for self.frameDuration property

- (NSTimeInterval) frameDuration
{
  return self.rgbAssetDecoder.frameDuration;
}

// Currently, no asset that can be decoded can support an alpha channel

- (BOOL) hasAlphaChannel
{
	return TRUE;
}

// Asset decoding returns only keyframes, but note that currently only 1
// frame can be loaded into memory at a time.

- (BOOL) isAllKeyframes
{
	return TRUE;
}

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
